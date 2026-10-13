# v3.0.0 agent, provider and embedding audit

This is a mechanism-oriented manual review of the modules below: request cost,
bounded work, cancellation, state ownership and tool/result correctness. A retained
module is not a claim that every possible host/provider behavior was exercised.
The separate bridge, companion transport and UI library are outside this audit.
The excluded network module IDs are `net/bridge`, `net/bridge_commands`,
`net/bridge_connection`, `net/relay`, `net/relay_link` and `net/transport`.
Their calls from reviewed modules are integration boundaries, not an audit of
those excluded implementations.

The release removes two quadratic paths: fragmented SSE lines now accumulate
pieces until a complete line arrives, and tool-result repair indexes the current
batch once. Prose previews no longer retain a second copy of tool arguments.
The authoritative stream parser retains its existing byte and call limits.

Shared tool validation preserves already-valid union types, stops recursive
schema walks at depth 32 or 8,192 visited values, and retains at most 16 errors.
Oversized declared arrays fail before member coercion. Invalid concurrency
settings fall back to eight workers instead of stranding a batch. Small native
receipts expose useful text, status, revisions and an available detail reference
immediately; larger receipts keep the exact retained-reader workflow. Superseded
post-hook references and unavailable readers remain hidden.

Anthropic prompt accounting includes uncached, cache-read and cache-creation
tokens because all occupy context. Cached reads feed the existing common usage
metrics. Cost remains an approximate list-price calculation, without new cache
discount billing claims.

Responses tool assembly binds item IDs, call IDs and output positions to one
slot. Full argument events replace streamed fragments, and nonempty final output
clears superseded partial calls. Streamed and whole responses enforce the shared
64-call and 256,000-byte argument limits; exceeding them is a terminal failure.
Statistics reload now restores lifetime model first/last-use dates and hour totals.

`conversation_search` adds `scope=all|conversations|pastes`, avoids constructing
duplicate message arrays, returns structured IDs/paths, and checks cancellation.
A pass reads at most 128 pasted files/8 MiB and scans at most 12,000 conversation
entries/8 MiB. Executor reads and individual retained messages are whole values,
so the last value may cross the byte budget. A limited or unreadable search is
explicitly incomplete; use `conversation_list`/`conversation_read` or `file_search`
on an exact paste path to narrow it. Schema limits prevent silently dropping
extra todo items, question choices, or oversized memory writes.

Metadata tools share a 32-entry, 60-second native product cache with explicit
`refresh=true`; game counts and uptime remain live. They return structured
identities, reject missing/ambiguous IDs and unsuccessful/empty API documents,
and carry cancellation into network phases. Native `place_info` remains usable
without executor HTTP; its web fallback still reports capability failure.

Virtual input tracks up to 32 held keys/buttons by owning conversation and
provider, with one watcher while cleanup remains eligible. Stop, tool revocation,
epoch replacement and unload attempt release; native downs that return after an
early release are released again. Accepted or uncertain downs/clicks never trigger
a second provider's press. Failed releases retain ownership for explicit `up`
recovery. Explicit mouse coordinates require a provider that can position the
cursor; right-button fallback requires the matching right-button release API.

The supplemental review covers all ten `ui/chat` modules in full, including
virtualized messages, bounded replay, lazy activity details, draft ownership and
listener cleanup. The composer now disconnects its parent resize listener on
destruction. Provider editor tests are revoked on close or connection/model edits;
late test results and model discovery cannot overwrite newer UI state.

| Module | Reviewed mechanism and disposition |
| --- | --- |
| `agent/context` | Compaction, calibration, pairing and persistence. Replaced sibling/call rescans with linear batch indexing; remove duplicate receipts and fill absent outcomes. |
| `agent/hooks` | Snapshot iteration, removals during callbacks and protected observers; retained. |
| `agent/loop` | Stable request catalogue, hook isolation, context recovery, repeat breaker and ordered tool results; retained. |
| `agent/permissions` | Scoped approvals, late settlement, revocation and rule/mode precedence; retained. |
| `agent/pricing` | Generated catalogue provenance and lookup paths reviewed; generated data untouched. Unknown-model substring scans remain a possible future optimization. |
| `agent/prompt` | Stable prefix, offered-tool-specific sections and bounded memory/skill references; retained. |
| `agent/registry` | Discovery/dispatch agreement, schema boundaries, deadlines and ordered concurrent results. Hardened concurrency settings. |
| `agent/schema` | JSON repairs preserve string bodies; added union preservation and bounded recursive validation/error output. |
| `agent/session` | Admission, epoch cancellation, event fanout, preserved policies and bounded restoration candidates; retained. |
| `agent/state` | Per-session todo ownership, bounded memory values and sorted-copy key inventory; retained. Tool schemas now declare write limits. |
| `agent/stats` | Event/usage observation, debounce and day retention reviewed. Restore persisted lifetime model/hour maps and reject invalid counter values. |
| `agent/stream` | Coalesced previews and separate clipping flags; omit tool argument retention in preview assemblers. |
| `agent/subagent` | Admission reservations, parent epochs, report collection, queue/worker ownership and context release; retained. |
| `agent/tool_result` | Bounded graph snapshot, post-hook identity and scoped readers. Inline fitting summary/reference receipts to avoid redundant model round trips. |
| `agent/transcript` | Independent retention lanes, grouped eviction and legacy recovery; retained. |
| `agent/usage` | Message estimates and recorded/estimated accounting; retained and now receives complete cached Anthropic input counts. |
| `provider/anthropic` | Wire blocks/signatures, stream limits and retry ownership reviewed. Normalize all prompt-token categories. |
| `provider/catalog` | Explicit presets, auth defaults and absence of guessed model lists; retained. |
| `provider/chat` | Protocol selection and common headers; retained. |
| `provider/community_key` | Official endpoint eligibility and explicit apply boundary; retained. |
| `provider/models` | Scoped cache, draft isolation, stale-result rejection and reported model IDs; retained. |
| `provider/openai` | Request ceilings, scoped repairs, response assembly and terminal errors; retained. |
| `provider/proxy` | Exact-route eligibility, bounded explicit refusal recovery and observer rechecks; retained. |
| `provider/registry` | Key rotation, URL/auth selection, record validation and fallback health; retained. |
| `provider/responses` | Input/tool conversion, stream/final assembly and endpoint restrictions reviewed. Bind call/item/output aliases, replace full arguments, discard superseded partial calls and enforce call/argument limits. |
| `provider/traits` | Longest documented family matching, explicit overrides and effort clamping; retained. |
| `embedding/scope` | Schema copies, finite JSON validation, owned resources and identity-guarded tool removal; retained. |
| `embedding/sdk` | Admission rejection, synchronous completion, cancellation epochs and cleanup; retained. |
| `net/headers` | Case-insensitive merge and later-map precedence; retained. |
| `net/http` | Native worker ownership, bounded responses, cancellation/deadlines and retry termination; retained. Relay internals excluded. |
| `net/sse` | BOM/CRLF framing, limits, completion and call assembly. Use fragment lists instead of repeated growing-line copies; optional prose-only assembly. |
| `net/ua` | Required identity and configurable header precedence; retained. |
| `net/url` | Parsed host/path/query preservation and local-address handling; retained. |
| `net/ws` | Native worker/connection limits and pre-/post-send failure classification; retained. |
| `tools/agentself` | Todo/memory/question contracts, report collection and conversation tools. Bounded cooperative search, explicit scopes and structured search evidence. |
| `tools/input` | Provider acceptance, partial outcomes, coordinates, ownership and cancellation. Prevent duplicate fallback presses, retain original release routes and clean up pending/persistent holds. |
| `tools/meta` | Native metadata reuse, response identity, capability discovery and cancellation. Added cache, refresh, semantic failure handling and structured results. |
| `ui/chat/activity` | Full source read: lazy receipt/detail construction, retained result projection, four-per-slice child mounting and timer cleanup; retained. |
| `ui/chat/composer` | Full source read: versioned session drafts, yielding send settlement, attachments, context refresh and responsive geometry. Disconnect the parent resize listener on destruction. |
| `ui/chat/context` | Full source read: coalesced context breakdown refresh and modal subscription cleanup; retained. |
| `ui/chat/loops` | Full source read: live runtime-job presentation and destruction unsubscribe; retained. |
| `ui/chat/message` | Full source read: staged Markdown fallback, virtualized chunks, bounded code previews, lazy reasoning formatting and timer cleanup; retained. |
| `ui/chat/prompts` | Full source read: static shared prompt inventory; retained. |
| `ui/chat/table` | Full source read: shared measured grid, coalesced reflow and listener cleanup; retained. |
| `ui/chat/todo` | Full source read: session-owned bounded plans, weak disclosure preferences and parent resize unsubscribe; retained. |
| `ui/chat/view` | Full source read with runtime reviewer: generation-owned replay, 12-row/6 ms slices, retained-row pruning, visibility suspension and subscription cleanup; retained. |
| `ui/chat/viewport` | Full source read: cached geometry, 24-item warm band, four-item/6 ms mounts, focus retention, spacer anchors and cleanup; retained. |
| `ui/panels/providers` | Full source read: draft isolation, preset edits, discovery, health updates, responsive reflow and cleanup. Tests now cancel on close/connection/model change and suppress stale feedback; detail discovery preserves newer provider selection. |
| `ui/settingspanes` | Full source read: settings bindings, facts subscriptions, import/export boundaries, control ownership and runtime delegation. Retained; excluded transport panes reviewed only at their UI call boundaries. |

| Registered tool | Reviewed disposition |
| --- | --- |
| `todo_write` | Declare the existing 24-item/160-character limits before execution; retain session ownership. |
| `todo_read` | Retain scoped plan/count readback. |
| `conversation_search` | Add scoped bounded cooperative search and structured match identities. |
| `conversation_list` | Retain exact IDs, bounded list paging and report collection. |
| `conversation_read` | Retain scoped transcript paging and explicit internal-message filtering. |
| `conversation_rename` | Retain named-thread validation and write permission. |
| `ask_user` | Declare 2–4 choices and 160-character choice limits; retain cancellation and answer ownership. |
| `memory_write` | Declare 120-character key/600-character value limits; retain write permission. |
| `memory_read` | Retain bounded scoped memory inventory. |
| `memory_forget` | Retain exact-key removal and write permission. |
| `dispatch_agent` | Retain admission, parent ownership and bounded status/report handling. |
| `agent_followup` | Retain owned child routing and bounded result collection. |
| `agent_status` | Retain session-aware status and child inventory. |
| `wait` | Retain cooperative waiting, cancellation and newly completed report collection. |
| `game_info` | Share native product facts while keeping live counts and uptime. |
| `place_info` | Add cache/refresh, native-first capability behavior and structured identity checks. |
| `user_lookup` | Reject ambiguous/missing identities and honor cancellation between HTTP phases. |
| `roblox_version` | Reject HTTP failures and empty release documents; return structured version evidence. |
| `key_press` | Preserve provider/conversation ownership, classify partial outcomes and clean up pending/persistent holds. |
| `mouse_click` | Share the input ownership contract; preserve explicit coordinates and correct button cleanup. |

Manually reviewed changed source, `test/release_agent.lua`, `test/release_input.lua`,
`test/release_provider_ui.lua` and affected existing input assertions before automated
execution. Focused verification after root's reviewed build/output gate:
`test/release_agent.lua`, `test/release_input.lua`, `test/release_provider_ui.lua`, `test/agent_efficiency.lua`,
`test/structured_results.lua`, `test/tool_cancellation.lua`,
`test/provider_compatibility.lua`, and applicable existing conversation/self-tool
cases. These synthetic tests do not measure native Roblox/executor latency.
Actual results are recorded by the release coordinator after execution.
