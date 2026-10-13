# Runtime and integration audit for 3.0.0

This audit covers the 37 runtime modules assigned to the runtime workstream,
ten integration tool modules, ten shared UI modules and seventeen additional UI
modules listed below, plus the targeted composer listener cleanup. Source was read before selecting
changes. The bridge, companion, desktop launcher and UI LIB are excluded. Generated
source references and embedded assets are not edited. A retained disposition means
the existing implementation was examined and no change was justified by this
efficiency pass; it is not a claim of native Roblox or executor validation.

## Implemented changes

- Debounced work retains one scheduled wakeup and the latest packed arguments.
  Burst events no longer allocate one waiting callback per update. Cancellation
  releases arguments immediately; a handler can yield and schedule another call.
- Prompt skill inventories reuse at most 3 KiB of rendered text for five seconds.
  Explicit listing/body reads stay fresh. Saves, removals, enable changes and
  configuration replacement invalidate the cache. Skill bodies are not cached.
- UTF-8 validation skips ASCII runs in the native string matcher. Repair copies
  contiguous valid spans, preserving the same invalid-byte positions and one
  replacement character per malformed byte.
- Remote capture retention uses a private queue with amortized constant-time
  eviction. Public ordering, limits, pins, completion updates and cursor gaps are
  unchanged. Summary/byte reads avoid copying unrequested typed graphs; returned
  mutable sections remain detached from storage.
- IY command and plugin discovery expose result-budgeted continuation offsets.
  Plugin search includes store IDs. Plugin authoring accepts saved source paths.
  Store installation validates plain filenames, rechecks destinations after a
  download and verifies written bytes before registration. Removal validates its
  filename before touching IY or disk. Store output distinguishes saved files,
  registration requests and already-existing files.
- Gravity receipts carry concise text and structured evidence once. Official
  source reads reuse two immutable snapshots for five minutes (at most 4 MiB),
  with explicit refresh. Local source is always fresh and capped at 2 MiB.
- Remote capture schemas state supported actions, sections, methods and page
  bounds. Chat history supports stable backward sequence cursors and channel
  filtering within the tool budget. Background loop receipts include lifetime,
  channel and count, and input schemas advertise byte/character bounds.
- Unavailable confirmation dialogs complete cancellation instead of executing
  the pending action. Icons verify each requested embedded file independently
  before loading it, reuse mapped aliases and fall back to frames after refused
  or unverified writes. Mascot blink callbacks cannot alter stopped, replaced or
  destroyed animation state.
- Sweeping one conversation's active question presents the next retained question
  from another conversation. The composer disconnects its parent-size listener
  when its own shell is destroyed.

## Runtime dispositions

| Module | Disposition and evidence reviewed |
| --- | --- |
| `attachments` | Retained: verified writes, exact inserted bytes, ordered/idempotent uploads, owner checks, 10 MiB file and 32 MiB pending budgets. |
| `caps` | Retained: one-time optional function probes, protected environment access, explicit unavailable capabilities and dynamic Gravity check. |
| `changes` | Retained: 30-batch/300-field history, pinned identities, complete Undo preflight and conditional partial recovery. |
| `chatbot` | Retained: isolated text-only inference, bounded 20-message queue/memory, 2,000 input IDs, duplicate suppression and live ownership checks. |
| `chatloops` | Retained: three active loops, 20 recent jobs, serial sends, minimum interval and round-robin dispatch, stop/revocation cleanup. |
| `clock` | Changed: debounce burst scheduling. Reviewed precise/fallback clocks, identity restoration, intervals, deadlines and cooperative native continuations. |
| `community` | Retained: constant-cost persistent invitation cadence and malformed timestamp handling. |
| `config` | Retained: merged defaults, debounced saves and complete replacement events; benefits from the shared debounce change. |
| `config_transfer` | Retained: 8 MiB input cap, bounded recursive validation, version/type checks and private transfer semantics. |
| `conversation_folders` | Retained: 64-folder limit, alternating verified snapshots, future/unreadable format protection and stable IDs. |
| `dispose` | Retained: reverse-order cleanup, unregister-on-release, reentrant drain guard and error containment. |
| `explorer` | Retained: bounded branches/query snapshots/rows, cursor signatures and TTL, selection revisions and property observation ownership. |
| `gamechat` | Retained: 100-entry history, message-ID/echo deduplication, code-point limits and modern/legacy routing. |
| `gravity` | Retained: resolves live context per action, validates setting batches, guarded native effects, actual control ranges and pagination. |
| `images` | Retained: eight image references, per-image/message byte limits, session ownership and protocol-only expansion. |
| `instance_edits` | Retained: bounded preflighted field batches, observed write results, conditional recovery, exact hierarchy selection/parent guards. |
| `instance_fields` | Retained: protected reads/writes and field/type validation; actual engine access remains authoritative. |
| `instance_paths` | Retained: nonexecuting bracket parser, duplicate-name rejection and bounded diagnostic ancestor traversal. |
| `instance_refs` | Retained: weak epoch-scoped identities, bounded 2,048 observers, explicit pins and unload release. |
| `instance_scan` | Retained: incremental child traversal, early page stop, cooperative checks, duplicate detection and 20,000-node ceiling. |
| `instance_schema` | Retained: curated property metadata and per-class cache; returned name arrays do not expose the cache. |
| `iy` | Retained: ambient/internal engine selection, serialized load attempts, live environment lookup and owned GUI guard. |
| `iy_control` | Retained: native event/alias/waypoint/settings validation, paginated inspection and in-place tables. |
| `iy_plugins` | Retained: bounded authored plugins, per-filename writer ownership, syntax/table checks and single setup evaluation. Tool path loading now feeds this same implementation. |
| `iy_store` | Changed: filename boundaries, destination recheck and verified installation. Reviewed ten-minute catalog cache, ranked matching and existing-file behavior. |
| `legacy_values` | Retained: compatibility coercions and diagnostics; scalar/text coordinate paths reject nonfinite numbers, typed replay uses `values`. |
| `log` | Retained: 400-entry history with block eviction and centralized secret redaction. |
| `native_exports` | Retained: bounded frozen capture exports, verified unique destinations, multipart completion manifest and selected metadata limits. |
| `place` | Retained: one in-flight background metadata request; prompt readers reuse known identity/name. |
| `remote_capture` | Retained: explicit lifecycle, owned hooks/connections, incoming cap, scope/admission checks, duration and agent revocation. |
| `remote_hooks` | Retained: inert import, reusable forwarding cells, detached routing probes and explicit unverified native Invoke coverage. |
| `remote_store` | Changed: private queue and selective copying. Reviewed pending/pin budgets, late outcomes, frozen exports, imports and generation invalidation. |
| `remote_targets` | Retained: centralized exact selection/scope resolution and remote class checks. |
| `signal` | Retained: no per-fire handler snapshot allocation, stable captured boundaries, disconnect/clear behavior, error isolation and recursion cap. |
| `skills` | Changed: bounded prompt-only cache and invalidation. Reviewed frontmatter, enabled policy, explicit fresh reads and UTF-8 tool continuations. |
| `util` | Changed: ASCII-run validation and span repair. Table/JSON semantics and UTF-8 truncation contracts remain unchanged. |
| `values` | Retained: exact nil arity, typed bounded graphs, cycle/alias inspection, replay validation and exact-path portable source. |

## Integration tool dispositions

| Module | Disposition and exported tools reviewed |
| --- | --- |
| `chat` | Changed `chat_history` pagination/filter/budget and `chat_send` input contract; bot channel ownership remains authoritative. |
| `chatloops` | Changed `chat_bot`, `auto_chat`, `quiz_bot`, `auto_reply` lifecycle receipts/input schemas and status/stop ID guidance. Existing bounded job lifecycle remains shared. |
| `gravity` | Changed shared receipts for status, launch, shapes, control, configure, shape, target, keybind, favorite, parts/control and plugin writes; plugin source reads advertise refresh. Existing per-action validation and risk/capability scopes reviewed. |
| `gravity_parts` | Changed repeated query normalization to once per listing and detached returned physics settings. Held-ID ordering, selection ceilings and guarded native changes retained. |
| `gravity_plugins` | Changed official source pagination cache and local read cap. Reviewed per-name write locks, setup deadline, staleness checks and registration cleanup. |
| `iy` | Changed command/plugin pagination, saved-path authoring, concise control receipts, bounded command schema and honest install output. Reviewed status, selectors, configuration, source reads and removal. |
| `remote_capture` | Changed schemas for lifecycle, call listings, graph/byte reads, filters, replay preparation and rules. Reviewed export/import, caller/source review/export and authorization ownership. |
| `remote_native` | Changed listing continuation/page-size contract; removed unused dependencies. Exact prepared targets and typed call dispatch retained. |
| `remote_replay` | Retained: bounded expiring immutable plans/source reviews, source/rule revision guards and at-most-once dispatch. |
| `remote_transport` | Changed legacy argument coercion to construct only the requested Roblox value type. Typed validation, nil arity, observation correlation and outstanding native calls retained. |

## Exact integration tool ledger

Names were checked against the JSON exported by `tools/site_catalog.lua` from the
3.0.0 bundle (174 tools). This table accounts for eight chat tools, thirteen
Gravity tools, ten IY tools and fourteen capture/replay/source tools: 45 exact
names. The release owner's ledger covers the remaining direct remote/signal
tools. Protected `ui_library_docs` is explicitly excluded from modification.

| Tool | Disposition |
| --- | --- |
| `auto_chat` | Changed: bounded message schema and explicit channel/count/interval/expiry receipt; shared loop lifecycle retained. |
| `auto_reply` | Changed: bounded trigger/response schema and lifetime receipt; serial reply ownership retained. |
| `chat_bot` | Changed: explicit bot lifetime/channel/count receipt; independent inference, deduplication and bounded memory retained. |
| `chat_history` | Changed: channel filtering, stable backward sequence cursors and result-budgeted chronological pages. |
| `chat_loop_status` | Changed: exact-ID/history schema guidance; bounded retained jobs and score snapshots retained. |
| `chat_loop_stop` | Changed: exact-ID/all schema guidance; shared immediate stop and submitted-message semantics retained. |
| `chat_send` | Changed: advertised UTF-8 byte bounds; native code-point limits, channel routing and bot ownership retained. |
| `quiz_bot` | Changed: bounded questions/answers/aliases and explicit lifetime receipt; first-answer scoring and round limits retained. |
| `gravity_configure` | Changed: concise receipt with structured evidence once; whole-batch validation and native setting effects retained. |
| `gravity_control` | Changed: concise receipt with structured evidence once; native lifecycle handlers and cancellation retained. |
| `gravity_favorite` | Changed: concise receipt with structured evidence once; native favorite table and persistence retained. |
| `gravity_keybind` | Changed: concise receipt with structured evidence once; live key validation/conflict detection retained. |
| `gravity_launch` | Changed: concise live-status receipt; existing connection reuse and explicit forced reload retained. |
| `gravity_part_control` | Changed: concise receipt and detached returned physics settings; exact selection and native action guards retained. |
| `gravity_parts` | Changed: query normalization once per listing and concise count/continuation receipt; stable claim-ID ordering retained. |
| `gravity_plugin_read` | Changed: two-entry/4 MiB/five-minute official-source cache, explicit refresh and fresh bounded local reads. |
| `gravity_plugin_write` | Changed: concise validation/registration receipt; verified source writes, writer locks and one setup evaluation retained. |
| `gravity_shape` | Changed: concise receipt with structured evidence once; real control units, selected-shape button checks and cleanup retained. |
| `gravity_shapes` | Changed: concise count/continuation receipt with structured catalog once; live shape/control inspection retained. |
| `gravity_status` | Changed: concise status receipt with structured state once; current engine/context lookup retained. |
| `gravity_target` | Changed: concise receipt with structured evidence once; ambiguous-player rejection and native target table retained. |
| `iy_cmd` | Changed: bounded command schema and clearer direct invocation guidance; native dispatch behavior retained. |
| `iy_cmds` | Changed: result-budgeted continuation, bounded signatures/descriptions and malformed alias filtering. |
| `iy_control` | Changed: concise receipt with structured evidence once; native aliases/events/waypoints/settings validation retained. |
| `iy_players` | Retained: IY's live selector resolution, bounded readable results and available-selector guidance. |
| `iy_plugin_install` | Changed: safe plain filename, bounded download, cancellation/destination recheck, verified bytes and honest registration request receipt. |
| `iy_plugin_read` | Retained: bounded guide/template/source slices with continuation and live plugin source lookup. |
| `iy_plugin_search` | Changed: full ranked search, result-budgeted pages, continuation offsets and installable store IDs. |
| `iy_plugin_uninstall` | Changed: canonical plain filename validation before IY removal or disk deletion. |
| `iy_plugin_write` | Changed: saved source-path input and concise receipt; existing locked validation/setup/write lifecycle retained. |
| `iy_status` | Retained: live ambient/internal IY status and availability reporting. |
| `remote_caller_source` | Retained wrapper: read-only caller source/decompile provenance through the shared source-document runtime. |
| `remote_capture_bytes` | Changed: explicit graph/byte selector bounds and storage lookup without full graph copies; exact byte continuation retained. |
| `remote_capture_read` | Changed: exact section/node/page schema and copying only requested sections; mutable results stay detached. |
| `remote_replay` | Retained: immutable plan/digest checks, at-most-once dispatch and outstanding InvokeServer handling. |
| `remote_replay_prepare` | Changed: method/revision schema contract; bounded expiring plan preparation remains non-dispatching. |
| `remote_rule` | Changed: action/method/policy/revision schema contract; exact-target rules and stop/revocation disarming retained. |
| `remote_script_export` | Retained: current review ID/digest validation and verified export of the exact reviewed portable source. |
| `remote_script_prepare` | Changed: method/revision schema contract; exact-path typed source review and expiry retained. |
| `remotes_calls` | Changed: explicit filters/page bounds; queue-backed ordered paging avoids FIFO shifts while preserving gaps and pins. |
| `remotes_capture` | Changed: exact lifecycle/mode/backend/duration schema; capture ownership, scope and revocation retained. |
| `remotes_export` | Retained: frozen bounded capture selection, verified output parts and completion manifest. |
| `remotes_filter` | Changed: exact method schema; future admission filtering remains separate from traffic blocking. |
| `remotes_import` | Retained: validated offline-only import, stale identity isolation and no implicit capture/replay. |
| `remotes_state` | Improved shared queue storage without changing state/coverage semantics; inspection remains inert. |

## Shared UI dispositions

| Module | Disposition and evidence reviewed |
| --- | --- |
| `assets` | Retained generated payloads; read decoder and module structure. Encoded image literals were excluded from the source logic audit; bundling reproduced unchanged bytes. |
| `brand` | Retained: bounded eleven-ray frame geometry, whole-pixel small-size coordinates and no asynchronous ownership. |
| `controls` | Retained: spinner cancellation, instance-owned switch signals, touch-scroll-aware slider drag/release/focus cleanup, measured segment widths and responsive key/value layout. |
| `icons` | Changed: per-file embedded-byte verification, alias asset reuse and mascot generation/lifetime guards. Read every fallback glyph and custom asset path; embedded assets remain unchanged. |
| `instance_icons` | Retained: generated class map, constant-time tile addressing, service/placeholder fallback and image assignment only on change. |
| `overlay` | Changed: unavailable confirmation dialogs cancel. Reviewed bounded toast count/height, timed pause ownership, modal fit coalescing, surface retirement, focus release and anchored menu subscriptions. |
| `primitives` | Retained: one current tween per element, destroy cleanup, measured text sizing, input callbacks, icon state collection and scroll/fade ownership. |
| `responsive` | Retained: generation-guarded delayed work, viewport and input sampling, scoped connection releases, safe rectangles and focused-field ancestor scrolling. |
| `theme` | Retained: one-time font probing, density/text bounds, native font fallback, reduced-motion durations and token-key-only rebuilding. |
| `window` | Retained: gesture release on focus/hide/layout/destroy, geometry limits, scoped subscriptions, whole-pixel placement and quiet persistence. |

## Additional UI dispositions

These seventeen modules were read in full. Retained here means no further change
was selected by this pass, including where another release workstream already
improved the current source. The bridge-related Cowork surface was reviewed as
existing client presentation only; bridge/relay implementations remain excluded.

| Module | Disposition and evidence reviewed |
| --- | --- |
| `changelog` | Retained: shared release data, read-marker update only after a modal exists, bounded modal viewport and wrapped release text. |
| `community` | Retained: optional invitation, quiet-period eligibility, active-view/draft checks, bounded cadence and connection/timer cleanup. |
| `markdown` | Retained: escaped RichText, matching backtick indexes, protected inline spans, fence preservation, table cell retention and bounded syntax highlighting. |
| `profile` | Retained: UTF-8 initial fallback, three thumbnail/preload attempts, late-result lifetime checks and provider-label subscription cleanup. |
| `project` | Retained: single open modal, browser-request feedback and selectable/copyable repository fallback. |
| `quickchat` | Retained: generation-guarded focus/hide, shared-session sends, failed-send draft retention, scoped theme/mode subscriptions and key-capture cancellation. |
| `settingsrows` | Retained: shared config-bound controls, commit/blur writes, field draft attributes, measured/reflowing control widths and action-label limits. |
| `panels/agents` | Retained current release implementation: keyed record/monitor rows, bounded refresh frequency, hidden-view work gating, identity checks and heartbeat/subscription cleanup. |
| `panels/ask` | Changed: session-scoped sweep now drains retained questions. Reviewed one-shot resolution, unavailable modal dismissal and direct/queued answers. |
| `panels/cowork` | Retained presentation: shared live status rows, guarded late download updates, capability feedback and status/config subscription cleanup. |
| `panels/home` | Retained: observed usage only, measured tiles/starters, fixed 26-week heatmap, debounced statistics refresh and destroyed-view guard. |
| `panels/logs` | Retained: sanitized selected detail fields, credential-aware URL display, bounded details, debounced history refresh and modal/subscription cleanup. |
| `panels/modelpicker` | Retained: single modal, signature-based row reuse, filtering, compact scroll ownership, late discovery guard and subscription cleanup. |
| `panels/permission` | Retained: queued one-shot allow/deny resolution, unavailable modal denial, argument review and headless duplicate suppression. |
| `panels/settings` | Retained: delegates every category to the shared pane renderer and owns no external listeners or background work. |
| `panels/settingsdialog` | Retained: category view caching, config-bound draft preservation, dirty invalidation, geometry reflow and observe-change cleanup. |
| `panels/tools` | Retained: registry-driven groups, capability/risk display, permission controls, preserved list position and permission subscription cleanup. |

`chat/composer` received a targeted lifecycle correction: retain the parent's
`AbsoluteSize` connection and disconnect it in the shell's `Destroying` handler.
The full chat module audit belongs to the agent efficiency workstream. The
application shell, sidebar, conversations, boot and Code panel are covered by the
scripting workstream; provider/settings pane coverage belongs to agent efficiency.

Targeted cross-review also covered the release changes in `tools/world`,
`tools/instance_bulk`, the owned-input release state machine and Responses tool
argument assembly. Overlapping native input down/up findings were repaired by
agent efficiency and reviewed again. The shared GUI hold cleanup now dispatches
its end callback asynchronously during unload so a yielding native end cannot
block unrelated disposers; ordinary completion still awaits release evidence.

## Focused verification

`test/release_runtime.lua` covers burst scheduling/argument release, yielded
callbacks, UTF-8 boundary/error cases and ASCII work counts, inventory freshness,
capture queue ordering/gaps/pins/clear/export, selective reader copying, official
source cache bounds, IY pagination/path authoring and store filename/destination
guards, and chat backward cursors. These checks use the existing offline harness.
`test/release_ui.lua` checks unavailable/explicit confirmations, upgrading multiple
old icon files, alias reuse, refused/silent writes, extraction retry and mascot
callbacks after stop/destruction, and question queue progress after a session
sweep. These are lifecycle/data checks, not native
rendering or host input verification.
The added `test/release_tools.lua` prompt timeline checks exercise cancellation
and unload while begin/end overlap, including an independent disposer completing
before the native end returns.

Applicable existing focused suites are `test/execution_tools.lua`,
`test/tool_workflows.lua`, `test/native_workspace.lua`, `test/gravity.lua`,
`test/iy_control.lua`, `test/chat_loops.lua` and `test/chat_bot.lua`. The release owner controls the
manual input review, build, generated-output inspection and focused test gate.
No full native suite or Roblox/executor verification is claimed by this document.

## Executed focused verification

After the release owner reviewed build `3.0.0-e4d76a37659fdec8` and its generated
outputs, the following assigned suites ran serially. All final exits were zero;
logs are retained under `refer/release-3.0.0/`.

| Suite | Passing checks/assertions | Measured seconds |
| --- | ---: | ---: |
| `release_runtime.lua` | 108 | 1.588 |
| `release_ui.lua` | 22 | 0.192 |
| `native_workspace.lua` | 76 across 13 cases | 0.911 |
| `gravity.lua` | 116 | 3.927 |
| `iy_control.lua` | 176 | 1.643 |

The initial UI run stopped at a test-only mock callback signature error (exit 1,
0.358 seconds). The fixture was corrected and manually reviewed before the
successful retry; its initial log remains `release_ui.initial-failure.log`.
No client source changed during this verification pass.
